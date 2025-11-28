package com.provesi.securityguard.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.provesi.securityguard.client.OrderDetailClient;
import com.provesi.securityguard.client.OrdersClient;
import com.provesi.securityguard.model.OrderSummary;
import org.springframework.stereotype.Service;

@Service
public class OrderGuardService {

    private final OrdersClient ordersClient;
    private final OrderDetailClient orderDetailClient;

    public OrderGuardService(OrdersClient ordersClient, OrderDetailClient orderDetailClient) {
        this.ordersClient = ordersClient;
        this.orderDetailClient = orderDetailClient;
    }

    public JsonNode authorizeAndFetch(long orderId, String vendorId) {
        if (vendorId == null || vendorId.isBlank()) {
            throw new ForbiddenAccessException("No se pudo identificar el vendedor en el token");
        }

        OrderSummary order = ordersClient.fetchOrder(orderId);
        String owner = order.resolvedOwner();
        if (owner == null || owner.isBlank()) {
            throw new ExternalServiceException("ms-orders no devuelve ownerVendorId para validar autorización");
        }
        if (!owner.equalsIgnoreCase(vendorId)) {
            throw new ForbiddenAccessException("El pedido no pertenece al vendedor autenticado");
        }

        return orderDetailClient.fetchFullOrder(orderId);
    }
}
