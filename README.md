# mini SNMP library for ruby/mruby

## Requirements
 * ruby 1.8, 1.9, 2.0 or mruby

## Usage

### mruby

Add the following lines to build_conf.rb and make.

```ruby
  conf.gem :git => 'https://github.com/iij/mruby-io.git'
  conf.gem :git => 'https://github.com/iij/mruby-socket.git'
  conf.gem :git => 'https://github.com/iij/mruby-pack.git'
  conf.gem :git => 'https://github.com/iij/msnmp.git'
```

There is a sample implementation of a snmpbulkwalk command.

    mruby bin/msnmpwalk -v 2c -c public host.example.com system

### ruby

install

    gem install msnmp

run

    msnmpwalk -v 2c -c public host.example.com system
