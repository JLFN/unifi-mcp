# List Device Tags

`GET /v1/sites/{siteId}/device-tags`  
operationId: `getDeviceTagPage`  

Returns all device tags defined within a site, which can be used for WiFi Broadcast assignments.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`id`|`UUID`|`eq` `ne` `in` `notIn`|
|`name`|`STRING`|`eq` `ne` `in` `notIn` `like`|
|`deviceIds`|`SET(UUID)`|`contains` `containsAny` `containsAll` `containsExactly`|
