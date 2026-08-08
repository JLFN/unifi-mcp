# Filtering

Explains how to use the filter query parameter for advanced querying across list endpoints,
including supported property types, syntax, and operators.

Some `GET` and `DELETE` endpoints support filtering using the `filter` query parameter.
Each endpoint supporting filtering will have a detailed list of filterable properties, their types, and allowed functions.

### Filtering Syntax

Filtering follows a structured, URL-safe syntax with three types of expressions.

#### 1. Property Expressions

Apply functions to an individual property using the form `<property>.<function>(<arguments>)`,
where argument values are separated by commas.

Examples:

id.eq(123) checks if id is equal to 123;
name.isNotNull() checks if name is not null;
createdAt.in(2025-01-01, 2025-01-05) checks if createdAt is either 2025-01-01 or 2025-01-05.

#### 2. Compound Expressions

Combine two or more expressions with logical operators using the form `<logical-operator>(<expressions>)`,
where expressions are separated by commas.

Examples:

and(name.isNull(), createdAt.gt(2025-01-01)) checks if name is null and createdAt is greater than 2025-01-01;
or(name.isNull(), expired.isNull(), expiresAt.isNull()) check is any of name, expired, or expiresAt is null.

#### 3. Negation Expressions

Negate any other expressions using the the form `not(<expression>)`.

Example:

not(name.like('guest*')) matches all values except those that start with guest.

### Filterable Property Types

The table below lists all supported property types.

TypeExamplesSyntaxSTRING'Hello, ''World''!'Must be wrapped in single quotes. To escape a single quote, use another single quote.INTEGER123Must start with a digit.DECIMAL123, 123.321Must start with a digit. Can include a decimal point (.).TIMESTAMP2025-01-29, 2025-01-29T12:39:11ZMust follow ISO 8601 format (date or date-time).BOOLEANtrue, falseCan be true or false.
