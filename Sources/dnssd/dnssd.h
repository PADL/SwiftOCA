#pragma once
#include <dns_sd.h>

typedef void (^DNSServiceRegisterReplyBlock)
(
    DNSServiceRef sdRef,
    DNSServiceFlags flags,
    DNSServiceErrorType errorCode,
    const char *name,
    const char *regtype,
    const char *domain
);

