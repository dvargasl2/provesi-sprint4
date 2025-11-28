package com.provesi.securityguard.security;

import com.provesi.securityguard.config.GuardProperties;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

@Component
public class VendorIdExtractor {

    private final GuardProperties guardProperties;

    public VendorIdExtractor(GuardProperties guardProperties) {
        this.guardProperties = guardProperties;
    }

    public String extractVendorId(Jwt jwt) {
        Object claim = jwt.getClaim(guardProperties.getVendorClaim());
        if (claim != null) {
            return claim.toString();
        }
        if (jwt.getSubject() != null) {
            return jwt.getSubject();
        }
        return null;
    }
}
