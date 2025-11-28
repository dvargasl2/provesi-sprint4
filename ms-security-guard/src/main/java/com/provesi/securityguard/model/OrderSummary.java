package com.provesi.securityguard.model;

import com.fasterxml.jackson.annotation.JsonProperty;

public record OrderSummary(
        Long id,
        @JsonProperty("ownerVendorId") String ownerVendorId,
        @JsonProperty("vendorId") String vendorIdCamel,
        @JsonProperty("vendor_id") String vendorIdSnake,
        @JsonProperty("customer_name") String customerName
) {
    public String resolvedOwner() {
        if (ownerVendorId != null) {
            return ownerVendorId;
        }
        if (vendorIdCamel != null) {
            return vendorIdCamel;
        }
        if (vendorIdSnake != null) {
            return vendorIdSnake;
        }
        if (customerName != null) {
            return customerName;
        }
        return null;
    }
}
