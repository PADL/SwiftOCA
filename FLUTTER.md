Notes on possible Flutter interface
-----------------------------------

Presently investigating SwiftUI clones vs Flutter for embedded touchscreen UI, via [FlutterSwift](https://github.com/PADL/FlutterSwift). This document collects some notes on integrating the latter with Swift.

```
- <prefix>/<connectionID>/<oNo>/<type>

    prefix          oca/tcp, ocasec/tcp, oca/udp, ocaws/tcp
    connectionID    probably an IP address:port tuple, although could be an ephemeral ID returned from a connection broker
    oNo             object number of object being addressed
    type            string "event" or "method"        
```

* method channels take a method (e.g. "4.2" to set a gain value) and arguments corresponding to the equivalent OCA types
* event channels connect the AsyncChannel from the observed property/properties, which are subscribed in the onListen() callback (probably need to use type erasure here to easily handle different types, doesn't make a difference on the Flutter end as types are dynamic)

```swift
public enum OcaPropertyChangeType: OcaUint8, Codable, Equatable {
    case currentChanged = 1
    case minChanged = 2
    case maxChanged = 3
    case itemAdded = 4
    case itemChanged = 5
    case itemDeleted = 6
}

public struct OcaPropertyChangedEventData<T: Codable>: Codable {
    let propertyID: OcaPropertyID
    let propertyValue: T
    let changeType: OcaPropertyChangeType
}

typealias FlutterPropertyChangedEventData = OcaPropertyChangedEventData<AnyCodable>
```

Method formats should just be the property value itself, although for bounded values OCA doesn't transmit the bounds in the setter.

Notification formats could be similar to OCA events, i.e. the property value itself with the trailing byte indicating the change type. Or we just retransmit the entire value.

In terms of encoding, we ideally want to avoid copies (but we want to be type and memory safe). There's no point converting to and from big-endian when we will be running on a little-endian machine in the same process. Flutter (at least with ObjC) uses type and value with variable length encoding if necessary. It would make sense probably to use something similar but if the receiver knows the types then we could eliminate the type information.

