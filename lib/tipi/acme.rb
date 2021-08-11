# frozen_string_literal: true

require 'openssl'
require 'acme-client'
require 'localhost/authority'

module Tipi
  module ACME
    class Error < StandardError
    end

    class CertificateManager
      def initialize(store:, challenge_handler:)
        @store = store
        @challenge_handler = challenge_handler
        @contexts = {}
        @requests = Polyphony::Queue.new
        @worker = spin { run }
      end

      ACME_CHALLENGE_PATH_REGEXP = /\/\.well\-known\/acme\-challenge/.freeze

      def challenge_routing_app(app)
        ->(req) do
          (req.path =~ ACME_CHALLENGE_PATH_REGEXP ? @challenge_handler : app)
            .(req)
        end
      end

      def setup_sni_callback(ctx)
        ctx.servername_cb = proc do |_socket, name|
          state = { ctx: nil }
          p servername_cb: name
          @requests << [name, state]
          wait_for_ctx(state)
          # Eventually we might want to return an error returned in
          # state[:error]. For the time being we handle errors by returning nil 
          state[:ctx]
        end
      end
    
      def wait_for_ctx(state)
        period = 0.00001
        while !state[:ctx] && !state[:error]
          orig_sleep period
          period *= 2 if period < 0.1
        end
      end
      
      def run
        loop do
          name, state = @requests.shift
          state[:ctx] = get_context(name)
        rescue => e
          state[:error] = e if state
        end
      end
    
      LOCALHOST_REGEXP = /\.?localhost$/.freeze

      def get_context(name)
        return localhost_certificate if name =~ LOCALHOST_REGEXP

        @contexts[name] = setup_context(name)
      end
    
      def setup_context(name)
        info = get_certificate(name)
        ctx = OpenSSL::SSL::SSLContext.new
        chain = parse_certificate(info[:certificate])
        cert = chain.shift
        puts "Certificate expires: #{info[:expired_stamp].inspect}"
        ctx.add_certificate(cert, info[:private_key], chain)
        ctx
      end

      CERTIFICATE_REGEXP = /(-----BEGIN CERTIFICATE-----\n[^-]+-----END CERTIFICATE-----\n)/.freeze
    
      def parse_certificate(certificate)
        certificate
          .scan(CERTIFICATE_REGEXP)
          .map { |p|  OpenSSL::X509::Certificate.new(p.first) }
      end

      def get_expired_stamp(certificate)
        chain = parse_certificate(certificate)
        cert = chain.shift
        cert.not_after
      end

      def get_certificate(name)
        entry = @store.get(name)
        return entry if entry

        provision_certificate(name).tap do |entry|
          @store.set(name, **entry)
        end
      end

      def localhost_context
        @localhost_authority ||= Localhost::Authority.fetch
        @localhost_authority.server_context
      end
    
      def private_key
        @private_key ||= OpenSSL::PKey::RSA.new(4096)
      end
    
      ACME_DIRECTORY = 'https://acme-v02.api.letsencrypt.org/directory'
    
      def acme_client
        @acme_client ||= setup_acme_client
      end
    
      def setup_acme_client
        client = Acme::Client.new(
          private_key: private_key,
          directory: ACME_DIRECTORY
        )
        account = client.new_account(
          contact: 'mailto:info@noteflakes.com',
          terms_of_service_agreed: true
        )
        client
      end
    
      def provision_certificate(name)
        order = acme_client.new_order(identifiers: [name])
        authorization = order.authorizations.first
        challenge = authorization.http
      
        @challenge_handler.add(challenge)
        challenge.request_validation
        while challenge.status == 'pending'
          sleep(0.25)
          challenge.reload
        end
        raise ACME::Error, "Invalid CSR" if challenge.status == 'invalid'
      
        private_key = OpenSSL::PKey::RSA.new(4096)
        csr = Acme::Client::CertificateRequest.new(
          private_key: private_key,
          subject: { common_name: name }
        )
        order.finalize(csr: csr)
        while order.status == 'processing'
          sleep(0.25)
          order.reload
        end
        certificate = begin
          order.certificate(force_chain: 'DST Root CA X3')
        rescue Acme::Client::Error::ForcedChainNotFound
          order.certificate
        end
        {
          private_key: private_key,
          certificate: certificate,
          expired_stamp: get_expired_stamp(certificate)
        }
      end
    end
  
    class HTTPChallengeHandler
      def initialize
        @challenges = {}
      end
    
      def add(challenge)
        path = "/.well-known/acme-challenge/#{challenge.token}"
        @challenges[path] = challenge
      end
    
      def remove(challenge)
        path = "/.well-known/acme-challenge/#{challenge.token}"
        @challenges.delete(path)
      end
    
      def call(req)
        challenge = @challenges[req.path]
    
        # handle incoming request
        challenge = @challenges[req.path]
        return req.respond(nil, ':status' => 400) unless challenge
    
        req.respond(challenge.file_content, 'content-type' => challenge.content_type)
      end
    end    
  
    class CertificateStore
      def set(name, private_key:, certificate:, expired_stamp:)
        raise NotImplementedError
      end

      def get(name)
        raise NotImplementedError
      end
    end

    class InMemoryCertificateStore
      def initialize
        @store = {}
      end

      def set(name, private_key:, certificate:, expired_stamp:)
        @store[name] = {
          private_key:    private_key,
          certificate:    certificate,
          expired_stamp:  expired_stamp
        }
      end

      def get(name)
        entry = @store[name]
        return nil unless entry
        if Time.now >= entry[:expired_stamp]
          @store.delete(name)
          return nil
        end

        entry
      end
    end
  end
end
