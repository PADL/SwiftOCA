Notes on possible Flutter interface
-----------------------------------

Presently investigating SwiftUI clones vs Flutter for embedded touchscreen UI. This document collects some notes on integrating the latter with Swift.

```
- <prefix>/<connectionID>/<oNo>/<method>

    prefix          oca/tcp, ocasec/tcp, oca/udp, ocaws/tcp
    connectionID    probably an IP address:port tuple, although could be an ephemeral ID returned from a connection broker
    oNo             object number of object being addressed
    method          method or property
```

e.g.

```
    oca/tcp/127.0.0.1:65000/1234/m/4.1    get (eg) gain value
                                          reply contains gain value
    oca/tcp/127.0.0.1:65000/1234/m/4.2    set (eg) gain value
                                          no reply
    oca/tcp/127.0.0.1:65000/1234/o/4.1    begin observing property changes
                                          no reply, but asynchronous events with "p" name
    oca/tcp/127.0.0.1:65000/1234/c/4.1    cancel observing property changes
                                          no reply
```

Method formats should just be the property value itself, although for bounded values OCA doesn't transmit the bounds in the setter.

Notification formats could be similar to OCA events, i.e. the property value itself with the trailing byte indicating the change type. Or we just retransmit the entire value.

In terms of encoding, we ideally want to avoid copies (but we want to be type and memory safe). There's no point converting to and from big-endian when we will be running on a little-endian machine in the same process. Flutter (at least with ObjC) uses type and value with variable length encoding if necessary. It would make sense probably to use something similar but if the receiver knows the types then we could eliminate the type information.

