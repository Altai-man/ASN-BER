use ASN::Parser;

class ASN::Parser::Async {
    has Supplier::Preserving $!out = Supplier::Preserving.new;
    has Supply $!values = $!out.Supply;
    has Buf $!buffer = Buf.new;
    has ASN::Parser $!parser = ASN::Parser.new(:$!type);
    has $.type;
    has $!debug = so %*ENV<ASN_BER_PARSER_DEBUG>;

    method values(--> Supply) {
        $!values;
    }

    method process(Buf $chunk) {
        $!buffer.append: $chunk;
        loop {
            # Minimal message length
            last if $!buffer.elems < 2;
            last unless $!parser.is-complete($!buffer);
            # Cut off tag, we know what it is already in this specific case
            $!parser.get-tag($!buffer);
            my $length = $!parser.get-length($!buffer);
            # Tag and length are already cut down here, take only value
            my $item-octets = $!buffer.subbuf(0, $length);
            $!out.emit: $!parser.parse($item-octets, :$!debug, :!to-chop);
            $!buffer .= subbuf($length);
        }
    }

    method close() {
        $!out.done;
    }
}
