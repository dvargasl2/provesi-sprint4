package com.provesi.securityguard.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.provesi.securityguard.security.VendorIdExtractor;
import com.provesi.securityguard.service.ExternalServiceException;
import com.provesi.securityguard.service.ForbiddenAccessException;
import com.provesi.securityguard.service.OrderGuardService;
import com.provesi.securityguard.service.OrderNotFoundException;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class OrderGuardController {

    private final OrderGuardService orderGuardService;
    private final VendorIdExtractor vendorIdExtractor;

    public OrderGuardController(OrderGuardService orderGuardService, VendorIdExtractor vendorIdExtractor) {
        this.orderGuardService = orderGuardService;
        this.vendorIdExtractor = vendorIdExtractor;
    }

    @GetMapping("/orders/{orderId}/full")
    public ResponseEntity<?> secureFullDetail(
            @PathVariable("orderId") long orderId,
            @AuthenticationPrincipal Jwt jwt
    ) {
        String vendorId = vendorIdExtractor.extractVendorId(jwt);
        try {
            JsonNode detail = orderGuardService.authorizeAndFetch(orderId, vendorId);
            return ResponseEntity.ok(detail);
        } catch (ForbiddenAccessException e) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(error("forbidden", e.getMessage()));
        } catch (OrderNotFoundException e) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error("not_found", e.getMessage()));
        } catch (ExternalServiceException e) {
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY).body(error("upstream_error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(error("internal_error", e.getMessage()));
        }
    }

    private Map<String, String> error(String code, String message) {
        return Map.of(
                "error", code,
                "message", message == null ? "" : message
        );
    }
}
