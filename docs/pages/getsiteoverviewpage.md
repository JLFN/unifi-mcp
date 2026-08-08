# List Local Sites

`GET /v1/sites`  
operationId: `getSiteOverviewPage`  

Retrieve a paginated list of local sites managed by this Network application.
Site ID is required for other UniFi Network API calls.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`id`|`UUID`|`eq` `ne` `in` `notIn`|
|`internalReference`|`STRING`|`eq` `ne` `in` `notIn`|
|`name`|`STRING`|`eq` `ne` `in` `notIn`|
