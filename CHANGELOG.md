## 0.30 2020-07-15

* Rename project to Tipi
* Rearrange source code
* Remove HTTP client code (to be developed eventually into a separate gem)
* Fix header rendering in rack adapter (#2)

## 0.29 2020-07-06

* Use IO#read_loop

## 0.28 2020-07-03

* Update with API changes from Polyphony >= 0.41

## 0.27 2020-04-14

* Remove modulation dependency

## 0.26 2020-03-03

* Fix `Server#listen`

## 0.25 2020-02-19

* Ensure server socket is closed upon stopping loop
* Fix `Request#format_header_lines`

## 0.24 2020-01-08

* Move HTTP to separate polyphony-http gem

For earlier changes look at the Polyphony changelog.
