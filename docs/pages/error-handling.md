# Error Handling

Describes the standard API error response structure, including error codes,
status names, and troubleshooting guidance.

## Related Schemas

### Error Message

FieldTypeFormatDescriptionExamplecodestring--api.authentication.missing-credentialsmessagestring--Missing credentialsrequestIdstringuuidIn case of Internal Server Error (core = 500), request ID can be used to track down the error in the server log3fa85f64-5717-4562-b3fc-2c963f66afa6requestPathstring--/integration/v1/sites/123statusCodeintegerint32-400statusNamestring--UNAUTHORIZEDtimestampstringdate-time-2024-11-27T08:13:46.966Z
