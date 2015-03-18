# yora

**DESCRIPTION**

Ruby implementation of raft consensus protocol intended for study purpose.

**FEATURES**

Fault tolerant git server is used to demonstrate how to implement distributed fault tolerant service.

The flow

1. push ref into a git remote
2. server side update hook is invoked, new ref and commit# is passed as command to a coordinator
it hangs until got confirmation from that the command was applied then return zero as exit code

**SYNOPSIS**

Run an demo fault tolerant git server

    $cd sample
    $ruby git_server.rb 
    Usage:
	     git_server.rb --node=888,127.0.0.1:2358 [--join|--leave] [--peer=999,127.0.0.1:2359]

The git repository `data/${node_id}/gitit` is created.

**REQUIREMENTS**

* ruby 2.0
* bundler

**DEVELOPERS**

After checking out the source, run:

    $ bundle install
    $ bundle exec rake

These tasks will install any missing dependencies and run the tests

**LICENSE**

    (The MIT License)

    Copyright (c) 2014 Huy Le

    Permission is hereby granted, free of charge, to any person obtaining
    a copy of this software and associated documentation files (the
    'Software'), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
