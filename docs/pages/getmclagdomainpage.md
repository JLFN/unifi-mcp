# List MC-LAG Domains

`GET /v1/sites/{siteId}/switching/mc-lag-domains`  
operationId: `getMcLagDomainPage`  

Retrieve a paginated list of all MC-LAG Domains on a site.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`id`|`UUID`|`eq` `ne` `in` `notIn`|
|`name`|`STRING`|`eq` `ne` `in` `notIn` `like`|
|`peers.deviceId`|`SET(UUID)`|`contains` `containsAny` `containsAll` `containsExactly`|
|`metadata.origin`|`STRING`|`eq` `ne` `in` `notIn`|
