use ASN::Types;

class Parser {
    multi method parse(Buf $input is copy, ASNValue @values, :$debug) {
        my @params;

        # Chop off SEQUENCE tag and length
        self!get-tag($input);
        self!get-length($input);

        for @values.kv -> Int $i, ASNValue $value {
            my $tag = self!get-tag($input);
            my $length = self!get-length($input);
            if $input.elems == 0 {
                unless @values[$i..*].map(*.optional).all {
                    die "Part of content is missing";
                }
                last;
            }
            my $key = self!normalize-name($value.name);
            say "Parsing `$key`" if $debug;
            @params.push: $key;
            @params.push: self!parse-asn($input, $tag, $length, $value, :$debug);
            say "Parsed `$key`" if $debug;
        }
        @params.Map;
    }
    method !get-tag(Buf $input is rw --> Int) {
        my $tag = $input[0];
        $input .= subbuf(1);
        $tag;
    }

    method !get-length(Buf $input is rw --> Int) {
        my $length = $input[0];
        if $length <= 127 {
            $input .= subbuf(1);
            return $length;
        } else {
            my $octets = $input.subbuf(1, $length - 128);
            $input .= subbuf($length - 127);
            return self.parse($octets, Int);
        }
    }

    method !parse-asn(Buf $input is rw, Int $tag, Int $length, ASNValue $value, :$debug) {
        say "Index parsed is $tag" if $debug;
        say "Length of value is $length" if $debug;

        my $tag-to-be = self!calculate-tag($value);
        # Return default value right now
        if $tag-to-be !~~ $tag {
            with $value.default {
                say "Returned default value $_.perl()" if $debug;
                $input.prepend($tag, $length);
                return $_;
            }
            die "Incorrect tag!";
        }

        my $read-value = $input.subbuf(0, $length);
        $input .= subbuf($length);

        $value.choice.defined ??
                self!parse-choice($tag, $read-value, $value, :$debug) !!
                self.parse($read-value, $value.type, :$debug);
    }
    method !calculate-tag(ASNValue $value) {
        my $tag = 0;
        $tag += do given $value.type {
            when ASN::UTF8String {
                12
            }
            when ASN::OctetString {
                4
            }
            when Enumeration {
                10
            }
            when Positional {
                48
            }
        }
        with $value.choice {
            my %opts = $_;
            return %opts.map({ $_ ~~ Pair ?? $_.key.Int + 128 !! $_.value.ASN-tag-value + 64 given $_.value }).any;
        }
        $tag;
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

    multi method parse(Buf $input is rw, Int $type where $type.HOW ~~ Metamodel::ClassHOW, :$debug) {
        my $total = 0;
        for (0, 8 ... *) Z @$input.reverse -> ($shift, $byte) {
            $total +|= $byte +< $shift;
        }
        say "Parsing $total out of $input.perl()" if $debug;
        $total;
    }

    multi method parse(Buf $input is rw, ASN::UTF8String $str, :$debug) {
        my $decoded = $input.decode();
        say "Parsing `$decoded.perl()` out of $input.perl()" if $debug;
        $str.new($decoded);
    }

    multi method parse(Buf $input is rw, ASN::OctetString $str, :$debug) {
        my $decoded = $input.map({ .base(16) }).join;
        say "Parsing `$decoded.perl()` out of $input.perl()" if $debug;
        $str.new($decoded);
    }

    multi method parse(Buf $input is rw, $enum-type where $enum-type.HOW ~~ Metamodel::EnumHOW, :$debug) {
        say "Parsing `$input[0]` out of $input.perl()" if $debug;
        $enum-type($input[0]);
    }

    multi method parse(Buf $input is rw, Positional $a, :$debug --> Array) {
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
