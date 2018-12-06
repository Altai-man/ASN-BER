enum TagModes is export <Implicit Explicit Automatic>;

enum TagClass is export <Universal Application Context Private>;

role ASNSequence {
    method ASN-order {...}
}

role ASNSequenceOf[$type] {
    method type { $type }
}

role ASNSet {
}

role ASNSetOf[$type] {
    method type { $type }
}

role ASNChoice {
    has $.choice-value;

    method ASN-choice() {...}
    method ASN-value() { $!choice-value }

    method new($choice-value) { $?CLASS.bless(:$choice-value) }
}

# String traits
role ASN::StringWrapper {
    has Str $.value;

    # We _want_ it to be inherited, so `method` here,
    # instead of `submethod`
    method new(Str $value) { self.bless(:$value) }
    method BUILD(Str :$!value) {}
}

role ASN::Types::UTF8String does ASN::StringWrapper {}

multi trait_mod:<is>(Attribute $attr, :$UTF8String) is export {
    $attr does ASN::Types::UTF8String;
}

role ASN::Types::OctetString does ASN::StringWrapper {}

multi trait_mod:<is>(Attribute $attr, :$OctetString) is export {
    $attr does ASN::Types::OctetString;
}

# OPTIONAL
role Optional {}

multi trait_mod:<is>(Attribute $attr, :$optional) is export {
    $attr does Optional;
}

# DEFAULT
role DefaultValue[:$default-value] {
    method default-value() { $default-value }
}

multi trait_mod:<is>(Attribute $attr, :$default-value) is export {
    $attr does DefaultValue[:$default-value];
    trait_mod:<is>($attr, :default($default-value));
}

# [0] like tags
role CustomTagged[:$tag] {
    method tag(--> Int) { $tag }
}

multi trait_mod:<is>(Attribute $attr, :$tagged) is export {
    $attr does CustomTagged[tag => $tagged];
}

class ASNValue {
    # Common attributes
    has $.name;
    has $.type;
    has $.tag is rw;

    # Custom ones
    has $.default;
    has $.choice;
    has $.optional = False;
    has $.value;
    has $.is-pos = False;
}
#
## Number of types that can be used where mapping from Perl 6 native types into ASN.1 ones is LTA.
#
#role ASNChoice {
#    has $.asn-choice-value;
#    has $.asn-choice-description;
#}
#
class ASN-Null {}

#my class ASN::StringWrapper {
#    has Str $.value;
#
#    # We _want_ it to be inherited, so `method` here,
#    # instead of `submethod`
#    method new(Str $value) { self.bless(:$value) }
#    method BUILD(Str :$!value) {}
#}
#
#class ASN::UTF8String is ASN::StringWrapper {}
#
#class ASN::OctetString is ASN::StringWrapper {}
#
our $primitive-type is export = Int | Str | ASN::Types::UTF8String | ASN::Types::OctetString | ASN-Null;
