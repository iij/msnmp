# mini SNMP library for iij/mruby

## Requirements
 * ruby 1.8, 1.9, 2.0 or iij/mruby

## Usage

    git clone https://github.com/iij/msnmp.git
    cd msnmp
    mruby -Ilib bin/msnmpwalk -v 2c -c public host.example.com system
