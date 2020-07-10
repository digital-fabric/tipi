# frozen_string_literal: true

require 'hanami/api'

class ExampleApi < Hanami::API
  get '/hello' do
    'Hello world!'
  end

  get '/' do
    redirect '/hello'
  end

  get '/404' do
    404
  end

  get '/500' do
    500
  end
end

run ExampleApi.new
