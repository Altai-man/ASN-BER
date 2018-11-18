use ASN::Types;

class Parser {
    my %types = 0xC => Str;

    multi method parse(Buf $input is copy, ASNValue @values) {
        my @params;
        my $index = $input[0];
        my $length = $input[1];
        $input .= subbuf(2);
        my $context = Context;
        # As we are parsing a sequence
        for @values.kv -> Int $i, ASNValue $value {
            my $key = self!normalize-name($value.name);
            @params.push: $key;
            @params.push: self!parse-asn($input, $index, $value, $context);
        }
        @params.Map;
    }

    method !parse-asn(Buf $input is rw, Int $index is copy, ASNValue $value, TagClass $context) {
        if $context == Context {
            $index -= 128;
        }

        my $read-index = $input[0];

        # Return default value right now
        if $index != $read-index && $value.default.defined {
            return $value.default;
        }

        my $length = $input[1];
        my $read-value = $input.subbuf(2, $length);
        $input .= subbuf($length + 2);

        $value.choice.defined ??
                self!parse-choice($read-value, $value) !!
                self.parse($read-value, $value.type);
    }

    method !parse-choice(Buf $input is rw, ASNValue $value) {
        my $selector = $input[0] - 128;
        my Pair $choice-pair = $value.choice[$selector];
        my $inner-choice-buffer = $input.subbuf(2);
        $choice-pair.key => self.parse($inner-choice-buffer, $choice-pair.value);
    }

    method !normalize-name(Str $name) {
        ~("$name" ~~ / \w .+ /)
    }

    multi method parse(Buf $input is rw, $type where $type ~~ Int && $type.HOW ~~ Metamodel::ClassHOW) {
        my $total = 0;
        for (0, 8 ... *) Z @$input.reverse -> ($shift, $byte) {
            $total +|= $byte +< $shift;
        }
        $total;
    }

    multi method parse(Buf $input is rw, Str) {
        $input.decode;
    }

    multi method parse(Buf $input is rw, $enum-type where $enum-type.HOW ~~ Metamodel::EnumHOW) {
        $enum-type($input[0]);
    }

    multi method parse(Buf $input is rw, Positional --> Array) {
        my $type = %types{$input[0]};
        my @a;
        loop {
            my $type = %types{$input[0]};
            my $length = $input[1];
            my $data = $input.subbuf(2, $length);
            @a.push: self.parse($data, $type);
            $input .= subbuf($length + 2);
            last if $input.elems == 0;
        }
        @a;
    }
}
