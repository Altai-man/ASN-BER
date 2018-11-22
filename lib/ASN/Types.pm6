enum TagClass is export <Universal Application Context Private>;

# OPTIONAL
role Optional {}

multi trait_mod:<is>(Attribute $attr, :$optional) is export {
    $optional does Optional;
}

# CHOICE
role Choice[:$choice-of] {
    method get-choice() { $choice-of }
}

multi trait_mod:<is>(Attribute $attr, :$choice-of!) is export {
    $attr does Choice[:$choice-of];
}

# DEFAULT
role DefaultValue[:$default-value] {
    method default-value() { $default-value }
}

multi trait_mod:<is>(Attribute $attr, :$default-value) is export {
    $attr does DefaultValue[:$default-value];
    trait_mod:<is>($attr, :default($default-value));
}

# SEQUENCE OF
role SequenceOf[:$sequence-of] {
    method get-sequence-type() { $sequence-of }
}

multi trait_mod:<is>(Attribute $attr, :$sequence-of) is export {
    $attr does SequenceOf[:$sequence-of];
}

class ASNValue {
    has $.name;
    has $.type;
    has $.default;
    has $.choice;
    has $.optional = False;
    has $.value;
    has $.sequence-of;
}

# Number of types that can be used where mapping from Perl 6 native types into ASN.1 ones is LTA.

subset ASN::UTF8String of Str is export;

subset ASN::OctetString of Str is export;
