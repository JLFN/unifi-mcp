# List LAGs

`GET /v1/sites/{siteId}/switching/lags`  
operationId: `getLagPage`  

Retrieve a paginated list of all LAGs (Link Aggregation Groups) on a site.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`id`|`UUID`|`eq` `ne` `in` `notIn`|
|`type`|`STRING`|`eq` `ne` `in` `notIn`|
|`switchStackId`|`UUID`|`eq` `ne` `in` `notIn` `isNull` `isNotNull`|
|`mcLagDomainId`|`UUID`|`eq` `ne` `in` `notIn` `isNull` `isNotNull`|
|`members.deviceId`|`SET(UUID)`|`contains` `containsAny` `containsAll` `containsExactly`|
|`members.portIdxs`|`SET(INTEGER)`|`contains` `containsAny` `containsAll` `containsExactly`|
|`metadata.origin`|`STRING`|`eq` `ne` `in` `notIn`|
