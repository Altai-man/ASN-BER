use ASN::BER;

class ASN::Serializer::Async {
    has Supplier::Preserving $!out = Supplier::Preserving.new;
    has Supply $!bytes = $!out.Supply;

    method bytes(--> Supply) {
        $!out;
    }

    method process(ASNType $value) {
        $!out.emit: $value.serialize;
    }

    method close() {
        $!out.done;
    }
}