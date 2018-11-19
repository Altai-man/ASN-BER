use ASN::BER;

class ASN::Parser::Async {
    has Supplier::Preserving $!out = Supplier::Preserving.new;
    has Supply $!values = $!out.Supply;
    has Buf $!buffer = Buf.new;
    has ASNType $.type;

    method values(--> Supply) {
        $!values;
    }

    method process(Buf $chunk) {
        $!buffer.append: $chunk;
        loop {
            last if $!buffer.elems < 2;
            my $length = $!buffer[1];
            last if $!buffer.elems < $length + 2;
            my $item-octets = $!buffer.subbuf(0, $length + 2);
            $!out.emit: $!type.parse($item-octets);
            $!buffer .= subbuf($length + 2);
        }
    }

    method close() {
        $!out.done;
    }
}