# List Radius Profiles

`GET /v1/sites/{siteId}/radius/profiles`  
operationId: `getRadiusProfileOverviewPage`  

Returns available RADIUS authentication profiles, including configuration origin metadata.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`id`|`UUID`|`eq` `ne` `in` `notIn`|
|`name`|`STRING`|`eq` `ne` `in` `notIn` `like`|
|`metadata.origin`|`STRING`|`eq` `ne` `in` `notIn`|
