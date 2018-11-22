use ASN::Types;

class Serializator {
    #| Types map:
    #| INTEGER -> Int
    #| UTF8String -> Str
    #| SEQUENCE -> Array
    #| ENUMERATED -> enum

    # INTEGER
    multi method serialize(Int $int is copy where $int.HOW ~~ Metamodel::ClassHOW, Int $index = 2, :$debug, :$mode) {
        my $int-encoded = Buf.new;
        my $bit-shift-value = 0;
        my $bit-shift-mask = 0xff;
        while True {
            my $byte = $int +& $bit-shift-mask +> $bit-shift-value;
            if $byte == 0 {
                $int-encoded.append(0) if $int-encoded.elems == 0;
                last;
            }
            $int-encoded.append($byte);
            # Update operands
            $bit-shift-value += 8;
            $bit-shift-mask +<= 8;
        }

        say "Encoding Int ($int) with index $index, resulting in $int-encoded.reverse().perl()" if $debug;
        Buf.new(|($index == -1 ?? () !! ($index, $int-encoded.elems)), |$int-encoded.reverse);
    }

    # ENUMERATED
    multi method serialize($enum-value where $enum-value.HOW ~~ Metamodel::EnumHOW, Int $index = 10, :$debug, :$mode) {
        my $encoded = $enum-value.^enum_values.Hash{$enum-value};
        say "Encoding Enum ($enum-value) with index $index, resulting in $encoded" if $debug;
        Buf.new(|($index == -1 ?? () !! ($index, 1)), $encoded);
    }

    # UTF8String
    multi method serialize(ASN::UTF8String $str, Int $index = 12, :$debug) {
        my $encoded = $str.encode;
        say "Encoding UTF8String ($str) with index $index, resulting in $encoded.perl()" if $debug;
        Buf.new(|($index == -1 ?? () !! ($index, $str.chars)), |$encoded);
    }

    multi method serialize(ASN::OctetString $str, Int $index = 4, :$debug) {
        my $buf =  Buf.new($str.comb(2).map('0x' ~ *).map(*.Int));
        say "Encoding OctetString ($str) with index $index, resulting in $buf.perl()";
        Buf.new(|($index == -1 ?? () !! ($index, $buf.elems)), |$buf);
    }

    # SEQUENCE
    multi method serialize(Array $sequence, Int $index = 48, :$debug, :$mode) {
        my $temp = Buf.new;
        for @$sequence -> $attr {
            if $attr ~~ ASNValue && $attr.default {
                next;
            }
            $temp.append(self.serialize($attr, :$debug));
        }
        # Tag + Length + Value
        say "Encoding Sequence (@sequence) with index $index into:" if $debug;
        Buf.new(|($index == -1 ?? () !! ($index, $temp.elems)), |$temp);
    }

    # Common method to enforce custom traits for ASNValue value
    # and call a serializer
    multi method serialize(ASNValue $common, :$debug, :$mode) {
        my $value = $common.value;
        # Don't serialize undefined values of type with a default
        return Buf.new if $common.default.defined && !$value.defined;

        if $common.choice ~~ List {
            $value does Choice[choice-of => $common.choice];
        }
        $value does DefaultValue[default-value => $_] with $common.default;
        $value does Optional if $common.optional;
        unless $common.sequence-of =:= Any {
            $value does SequenceOf[sequence-of => $_];
        }
        $common.choice !~~ List ??
                self.serialize($value, :$debug) !!
                self.serialize-choice($value, $common.choice, :$debug);
    }

    # CHOICE
    method serialize-choice($common, $choice-of, :$debug, :$mode) {
        my $value = %$choice-of{$common.key};
        my $index = $value ~~ Pair ?? $value.key !! $value.asn-tag-value;
        $index +|= 128; # Make index context-specific
        my $inner = self.serialize($common.value, -1);
        say "Encoding CHOICE ($common) with index $index into $inner.perl()" if $debug;
        Buf.new($index, $inner.elems, |$inner);
    }

    # Dying method to detect types not yet implemented
    multi method serialize($common, :$debug) {
        my $is-asn-type = $common.^roles.map(*.^name).grep(* eq 'ASNType').elems == 1;
        if $is-asn-type {
            return $common.serialize(:$debug);
        }
        die "NYI for: $common";
    }
}
