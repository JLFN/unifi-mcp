# List Switch Stacks

`GET /v1/sites/{siteId}/switching/switch-stacks`  
operationId: `getSwitchStackPage`  

Retrieve a paginated list of all Switch Stacks on a site.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`id`|`UUID`|`eq` `ne` `in` `notIn`|
|`name`|`STRING`|`eq` `ne` `in` `notIn` `like`|
|`members.deviceId`|`SET(UUID)`|`contains` `containsAny` `containsAll` `containsExactly`|
|`metadata.origin`|`STRING`|`eq` `ne` `in` `notIn`|
