# List Countries

`GET /v1/countries`  
operationId: `getCountries`  

Returns ISO-standard country codes and names,
used for region-based configuration or regulatory compliance.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`code`|`STRING`|`eq` `ne` `in` `notIn`|
|`name`|`STRING`|`eq` `ne` `in` `notIn` `like`|
