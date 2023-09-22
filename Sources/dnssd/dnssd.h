#pragma once

#include <dns_sd.h>

#ifndef __APPLE__
#include <Block/Block.h>
#endif

typedef void (^DNSServiceRegisterReplyBlock)
(
    DNSServiceRef sdRef,
    DNSServiceFlags flags,
    DNSServiceErrorType errorCode,
    const char *name,
    const char *regtype,
    const char *domain
);

