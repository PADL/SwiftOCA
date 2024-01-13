/// A (stateful) binary encoder.
struct Ocp1EncoderImpl: Encoder {
    private let state: Ocp1EncodingState

    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    init(state: Ocp1EncodingState, codingPath: [any CodingKey]) {
        self.state = state
        self.codingPath = codingPath
    }

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key>
        where Key: CodingKey
    {
        .init(KeyedOcp1EncodingContainer(state: state, codingPath: codingPath))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        UnkeyedOcp1EncodingContainer(state: state, codingPath: codingPath)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        SingleValueOcp1EncodingContainer(state: state, codingPath: codingPath)
    }
}
