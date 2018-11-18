use ASN::Types;

class Serializator {
    #| Types map:
    #| INTEGER -> Int
    #| UTF8String -> Str
    #| SEQUENCE -> Array
    #| ENUMERATED -> enum

    # INTEGER
    multi method serialize(Int $index, Int $int is copy where $int.HOW ~~ Metamodel::ClassHOW, TagClass $class) {
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
        Buf.new($index, $int-encoded.elems, |$int-encoded.reverse);
    }

    # ENUMERATED
    multi method serialize(Int $index, $common where $common.HOW ~~ Metamodel::EnumHOW, TagClass $class) {
        Buf.new($index, 1, $common.^enum_values.Hash{$common});
    }

    # UTF8String
    multi method serialize(Int $index, Str $str, TagClass $class) {
        my $delta = do given $class {
            when Application { 12 }
            when Context { 0 }
        }
        Buf.new($index +| $delta, $str.chars, |$str.encode);
    }

    # SEQUENCE
    multi method serialize(Int $index, Array $sequence, TagClass $class) {
        my $delta = do given $class {
            when Application {
                16;
            }
            when Context {
                0
            }
        }

        my $result = Buf.new($index +| $delta +| 32); # Enable complex type bits (32)

        my $temp = Buf.new;
        my $inner-index = do given $class {
            when Application { 0x80 }
            when Context { 0 }
        }
        for @$sequence -> $attr {
            if $attr ~~ ASNValue && $attr.default {
                $inner-index++ if $sequence !~~ SequenceOf;
                next;
            }
            $temp.append(self.serialize($inner-index, $attr, $sequence ~~ SequenceOf ?? Application !! Context));
            $inner-index++ if $sequence !~~ SequenceOf;
        }
        # Tag + Length + Value
        Buf.new(|$result, $temp.elems, |$temp);
    }

    # Common method to enforce custom traits for ASNValue value
    # and call a serializer
    multi method serialize(Int $index, ASNValue $common, TagClass $class) {
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
                self.serialize($index, $value, $class) !!
                self.serialize-choice($index, $value, $common.choice, $class);
    }

    # CHOICE
    method serialize-choice(Int $index, $common, $choice-of, TagClass $class) {
        # It is a complex type, so plus 0b10100000
        my $inner-index = 0x80; # Starting number for inner structures.
        my $common-key = $common.key;
        for @$choice-of -> $key {
            if $key.key eq $common-key {
                last
            } else {
                $inner-index++;
            }
        }
        my $inner = self.serialize($inner-index, $common.value, $class);
        Buf.new($index +| 0x20, $inner.elems, |$inner);
    }

    # Dying method to detect types not yet implemented
    multi method serialize(Int $index, $common, TagClass $class) {
        die "NYI for: $common";
    }
}
