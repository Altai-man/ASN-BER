use ASN::Types;

class Serializator {
    my $primitive-type =
            Int | Str |
            ASN::UTF8String | ASN::OctetString;

    #| Types map:
    #| INTEGER -> Int
    #| UTF8String -> ASN::UTF8String
    #| OctetString -> ASN::OctetString
    #| SEQUENCE -> Array
    #| ENUMERATED -> enum

    method !calculate-len(Buf $value, :$infinite) {
        with $infinite {
            return Buf.new(128);
        }
        if $value.elems <= 127 {
            return Buf.new($value.elems);
        }
        my $long = self.serialize($value.elems, -1);
        if $long.elems > 126 {
            die "The value is too long, please use streaming";
        }
        return Buf.new($long.elems + 128, |$long);
    }

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
        Buf.new(|($index == -1 ?? () !! ($index, |self!calculate-len($int-encoded))), |$int-encoded.reverse);
    }

    # ENUMERATED
    multi method serialize($enum-value where $enum-value.HOW ~~ Metamodel::EnumHOW, Int $index = 10, :$debug, :$mode) {
        my $encoded = $enum-value.^enum_values.Hash{$enum-value};
        say "Encoding Enum ($enum-value) with index $index, resulting in $encoded" if $debug;
        Buf.new(|($index == -1 ?? () !! ($index, 1)), $encoded);
    }

    # UTF8String
    multi method serialize(ASN::UTF8String $str, Int $index = 12, :$debug) {
        my $encoded = Buf.new($str.value.encode);
        say "Encoding UTF8String ($str.value() with index $index, resulting in $encoded.perl()" if $debug;
        Buf.new(|($index == -1 ?? () !! ($index, |self!calculate-len($encoded))), |$encoded);
    }

    # OctetString
    multi method serialize(ASN::OctetString $str, Int $index = 4, :$debug) {
        my $buf =  Buf.new($str.value.comb(2).map('0x' ~ *).map(*.Int));
        say "Encoding OctetString ($str.value() with index $index, resulting in $buf.perl()" if $debug;
        Buf.new(|($index == -1 ?? () !! ($index, |self!calculate-len($buf))), |$buf);
    }

    # SEQUENCE
    multi method serialize(Array $sequence, Int $index is copy = 16, :$debug, :$mode) {
        # COMPLEX element, so add 32
        $index += 32 if $index != -1;
        my $temp = Buf.new;
        say "Encoding Sequence (@sequence) with index $index into:" if $debug;
        for @$sequence -> $attr {
            if $attr ~~ ASNValue && $attr.default {
                next;
            }
            $temp.append(self.serialize($attr, :$debug));
        }
        # Tag + Length + Value
        Buf.new(|($index == -1 ?? () !! ($index, |self!calculate-len($temp))), |$temp);
    }

    # Common method to enforce custom traits for ASNValue value
    # and call a serializer
    multi method serialize(ASNValue $asn-node, :$debug, :$mode) {
        my $value = $asn-node.value;
        # Don't serialize undefined values of type with a default
        return Buf.new if $asn-node.default.defined && !$value.defined;
        return Buf.new if $asn-node.optional && !$value.defined || $value.elems == 0;

        if $asn-node.choice ~~ List {
            $value does Choice[choice-of => $asn-node.choice];
        }
        $value does DefaultValue[default-value => $_] with $asn-node.default;
        my $tag = ();
        with $asn-node.tag {
            $tag = $_ + 128; # Set context-bit
        }
        $asn-node.choice =:= Any ??
                self.serialize($value, |($tag), :$debug) !!
                self.serialize-choice($value, $asn-node.choice, :$debug);
    }

    # CHOICE
    method serialize-choice($value, $choice-of, :$debug, :$mode) {
        my $description = %$choice-of{$value.key};
        my $is-simple-implicit = $description ~~ Pair;
        my $index = $is-simple-implicit ?? $description.key !! $description.ASN-tag-value;
        # Set complex type bit
        $index += 32 unless $value.value ~~ $primitive-type;
        # Set APPLICATION content type if we are in APPLICATION mode

        if $is-simple-implicit {
            $index += 128;
        } else {
            $index += 64;
        }
        #$index +|= 128; # Make index context-specific
        say "Encoding CHOICE ($value) with index $index" if $debug;
        my $inner = $is-simple-implicit ?? self.serialize($value.value, -1) !! $value.value.serialize(:$debug, :index(-1));
        Buf.new($index, |self!calculate-len($inner), |$inner);
    }

    # Dying method to detect types not yet implemented
    multi method serialize($common, :$debug) {
        die "NYI for: $common";
    }
}
