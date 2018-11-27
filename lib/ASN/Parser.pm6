use ASN::Types;

class Parser {
    multi method parse(Buf $input is copy, ASNValue @values, :$debug) {
        my @params;
        my $index = $input[0];
        my $length = $input[1];
        $input .= subbuf(2);
        # As we are parsing a sequence
        for @values.kv -> Int $i, ASNValue $value {
            if $input.elems == 0 {
                unless @values[$i..*].map(*.optional).all {
                    die "Too less content";
                }
                last;
            }
            my $key = self!normalize-name($value.name);
            say "Parsing $key" if $debug;
            @params.push: $key;
            @params.push: self!parse-asn($input, $index, $value, :$debug);
        }
        @params.Map;
    }

    method !parse-asn(Buf $input is rw, Int $index is copy, ASNValue $value, :$debug) {
        my $read-index = $input[0];
        say "Index parsed is $read-index" if $debug;

        # Return default value right now
        if $index != $read-index && $value.default.defined {
            say "Returned default value $value.default()" if $debug;
            return $value.default;
        }

        my $length = $input[1];
        my $read-value = $input.subbuf(2, $length);
        $input .= subbuf($length + 2);

        say "Length of value is $length" if $debug;

        $value.choice.defined ??
                self!parse-choice($read-index, $read-value, $value, :$debug) !!
                self.parse($read-value, $value.type, :$debug);
    }

    method !parse-choice(Int $index, Buf $input is rw, ASNValue $value, :$debug) {
        say "Parsing CHOICE on $value.choice().perl() out of $input.perl(), index is $index" if $debug;

        my $item-index = $index +& 0b11011111;
        # Clear complex type bit if present
        if $index +& 64 == 64 {
        # APPLICATION tag
            $item-index -= 64;
        } elsif $index +& 128 == 128 {
        # Context-specific tag
            $item-index -= 128;
        } else {
        # Universal tag
        }

        my $item = $value.choice.grep({ (.value ~~ Pair ?? .value.key !! .value.ASN-tag-value) eq $item-index })[0];
        my $value-type = $item.value ~~ Pair ?? $item.value.value !! $item.value;
        if $value-type.^roles.grep({ .^name eq 'ASNType' }).elems == 1 {
            $input.unshift($index, $input.elems);
            $item.key => $value-type.parse($input, :$debug);
        } else {
            $item.key => self.parse($input, $value-type, :$debug);
        }
    }

    method !normalize-name(Str $name) {
        ~("$name" ~~ / \w .+ /)
    }

    multi method parse(Buf $input is rw, $type where $type ~~ Int && $type.HOW ~~ Metamodel::ClassHOW, :$debug) {
        my $total = 0;
        for (0, 8 ... *) Z @$input.reverse -> ($shift, $byte) {
            $total +|= $byte +< $shift;
        }
        say "Parsing $total out of $input.perl()" if $debug;
        $total;
    }

    multi method parse(Buf $input is rw, $str where $str ~~ ASN::UTF8String, :$debug) {
        my $decoded = $input.decode();
        say "Parsing `$decoded.perl()` out of $input.perl()" if $debug;
        $str.new($decoded);
    }

    multi method parse(Buf $input is rw, $str where $str ~~ ASN::OctetString, :$debug) {
        my $decoded = $input.map({ .base(16) }).join;
        say "Parsing `$decoded.perl()` out of $input.perl()" if $debug;
        $str.new($decoded);
    }

    multi method parse(Buf $input is rw, $enum-type where $enum-type.HOW ~~ Metamodel::EnumHOW, :$debug) {
        say "Parsing `$input[0]` out of $input.perl()" if $debug;
        $enum-type($input[0]);
    }

    multi method parse(Buf $input is rw, $a where $a ~~ Positional, :$debug --> Array) {
        say "Parsing SEQUENCE out of $input.perl()" if $debug;
        my @a;
        loop {
            my $length = $input[1];
            my $data = $input.subbuf(2, $length);
            @a.push: self.parse($data, $a.of);
            $input .= subbuf($length + 2);
            last if $input.elems == 0;
        }
        @a;
    }
}
