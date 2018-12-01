### ASN::BER

This module is designed to allow one make types support encoding and decoding based on ASN.1 rules.

#### Warnings

* This is an _alpha_. A lot of universal types are not even described and papercuts are everywhere.
* Main driving power beneath this is a desire to avoid writing every LDAP type
parsing and serializing code by hands. As a result, while some means to have more generic support
of ASN.1 are being prepared, contributing code to support greater variety of ASN.1 definitions
being expressed and handled correctly is appreciated.

#### Synopsis

```Perl6
#`[
World-Schema DEFINITIONS IMPLICIT TAGS ::=
BEGIN
  Rocket ::= SEQUENCE
  {
     name      UTF8String (SIZE(1..16)),
     message   UTF8String DEFAULT "Hello World",
     fuel      ENUMERATED {solid, liquid, gas},
     speed     CHOICE
     {
        mph    [0] INTEGER,
        kmph   [1] INTEGER
     }  OPTIONAL,
     payload   SEQUENCE OF UTF8String
  }
END
]

# Necessary imports
use ASN::Types;
use ASN::BER;

# ENUMERATED is expressed as enum
enum Fuel <Solid Liquid Gas>;

# Mark our class as ASNType
class Rocket does ASNType {
    has ASN::UTF8String $.name; # UTF8String
    has ASN::UTF8String $.message is default-value(ASN::UTF8String.new("Hello World")); # DEFAULT
    has Fuel $.fuel; # ENUMERATED
    has $.speed is choice-of(mph => (1 => Int), kmph => (0 => Int)) is optional; # CHOICE + OPTIONAL
    has ASN::UTF8String @.payload; # SEQUENCE OF UTF8String

    # `ASN-order` method is a single _necessary_ method
    # which describes order of attributes of type (here - SEQUENCE) to be encoded
    method ASN-order() {
        <$!name $!message $!fuel $!speed @!payload>
    }
}

my $rocket = Rocket.new(
        name => ASN::UTF8String.new('Falcon'),
        fuel => Solid,
        speed => mph => 18000,
        payload => [
            ASN::UTF8String.new("Car"),
            ASN::UTF8String.new("GPS")
        ]
);

say $rocket.serialize; # currently, only IMPLICIT tag schema used in LDAP is supported
# If contributed, it can look something like `$rocket.serialize(:explicit)` for explicit tagging.

# `$rocket.serialize(:debug)` - `debug` named argument enables printing of basic debugging messages

# Result: Blob.new(
#            0x30, 0x1B, # Outermost SEQUENCE
#            0x0C, 0x06, 0x46, 0x61, 0x6C, 0x63, 0x6F, 0x6E, # NAME, MESSAGE is missing
#            0x0A, 0x01, 0x00, # ENUMERATED
#            0x81, 0x02, 0x46, 0x50, # CHOICE
#            0x30, 0x0A, # SEQUENCE OF UTF8String
#                0x0C, 0x03, 0x43, 0x61, 0x72,  # UTF8String
#                0x0C, 0x03, 0x47, 0x50, 0x53); # UTF8String

say Rocket.parse($rocket-encoding-result); # Will return an instance of Rocket class parsed from `$rocket-encoding-result` Buf
```

#### ASN.1 "traits" handling rules

**This part is a design draft that might be changed in case of any issue that hinders development of LDAP**

The main concept is to avoid unnecessary creation of new types that just serve as envelopes for
actual data and avoid boilerplate related to using such intermediate types. Hence, when possible,
we try to use native types and traits.

#### Tagging schema

For now, encoding is done as if `DEFINITIONS IMPLICIT TAGS` is applied for an outermost type (i.e. "module").
Setting of other schemes is expected to be able to work via named arguments passed to `serialize`|`parse` methods.

#### Mapping from ASN.1 type to ASN::BER format

Definitions of ASN.1 types are made by use of:

* Universal types (`MessageID ::= INTEGER`)

Universal types are mostly handled with Perl 6 native types, currently implemented are:

| ASN.1 type      | Perl 6 type                |
|-----------------|----------------------------|
| INTEGER         | Int                        |
| OCTET STRING    | ASN::OctetString           |
| ENUMERATED      | enum                       |
| UTF8String      | ASN::UTF8String            |
| SEQUENCE        | class implementing ASNType |
| SEQUENCE OF Foo | Foo @.sequence             |

* User defined types (`LDAPDN ::= LDAPString`)

If it is based on ASN.1 type, just use this one; So:

```
LDAPString ::= OCTET STRING
LDAPDN ::= LDAPString
```

results in

```
has ASN::OctetString $.LDAPDN; # Ignore level of indirectness in type
```

* SEQUENCE elements (`LDAPMessage ::= SEQUENCE {...}`)

Such elements are implemented as classes with `ASNType` role applied and `ASN-order` method implemented.
They are handled correctly if nested, so `a ::= SEQUENCE { ..., b SEQUENCE {...} }` will translate `a` and include
`b` as it's part, calling `serialize` on that inner class instance.

* SET elements (`Foo ::= SET {}`)

Not yet supported.

* CHOICE elements

CHOICE elements are implemented using `choice-of` trait.
For same types tagging must be used to avoid ambiguity, it is usually done using context-specific tags.

```
A ::= SEQUENCE {
    ...,
    authentication AuthenticationChoice
}

AuthenticationChoice ::= CHOICE {
  simple  [0] OCTET STRING,
            -- 1 and 2 reserved
  sasl    [3] SaslCredentials } -- SaslCredentials begin with LDAPString, which is a OCTET STRING
```

becomes

```
class A {
    ...
    has $.authentication is choice-of(
            simple => (0 => ASN::OctetString),
            sasl   => (3 => Cro::LDAP::Authentication::SaslCredentials)) is required;
}

A.new(..., authentication => simple => ASN::OctetString.new("466F6F"));
```

`simple` is a key for internal pair, which consists of tag and CHOICE option type.

Another option, when there is no ambiguity, are usages of

* Universal type - `choice-of(a => Int, b => ASN::UTF8String)` is handled using appropriate universal type for a choice value.

* User-defined type with `APPLICATION`-wide tag.

If ASN.1 declares tag APPLICATION-wide, for example:

```
BindRequest ::= [APPLICATION 0] SEQUENCE {
    ...
}
```

it might be expressed with `ASN::BER` like that:

```
class BindRequest does ASNType {
    method ASN-order {...}
    method ASN-tag-value { 0 } # [APPLICATION 0]
}
```

Then when this type is used a part of CHOICE, internal pair of CHOICE values is replaced with explicit type:

```
class Request does ASNType {
    ...
    has $.protocol-op is choice-of(
            bindRequest => RequestBind,
    );
}
```

`ASN::Ber` will call method `ASN-tag-value` method of `RequestBind` instance and will use encode/parse it as APPLICATION-wide tag.

The difference is caused by `Context Specific` and `Application` tags being encoded differently.


#### ASN.1 type traits

##### Optional

Apply `is optional` trait to an attribute.

##### Default

Apply `is default-value` trait to an attribute. It additionally sets `is default` trait with the same value.
