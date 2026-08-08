# List DPI Applications

`GET /v1/dpi/applications`  
operationId: `getDpiApplications`  

Lists DPI-recognized applications grouped under categories. Useful for firewall or traffic analytics integration.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`id`|`INTEGER`|`eq` `ne` `in` `notIn`|
|`name`|`STRING`|`eq` `ne` `in` `notIn` `like`|
