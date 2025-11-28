package com.provesi.securityguard.client;

import com.provesi.securityguard.config.GuardProperties;
import com.provesi.securityguard.model.OrderSummary;
import com.provesi.securityguard.service.ExternalServiceException;
import com.provesi.securityguard.service.OrderNotFoundException;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;

@Component
public class OrdersClient {

    private final WebClient client;
    private final GuardProperties guardProperties;

    public OrdersClient(WebClient.Builder builder, GuardProperties guardProperties) {
        this.guardProperties = guardProperties;
        this.client = builder.baseUrl(guardProperties.getServices().getOrdersBaseUrl()).build();
    }

    public OrderSummary fetchOrder(long orderId) {
        try {
            return client.get()
                    .uri("/orders/{id}", orderId)
                    .accept(MediaType.APPLICATION_JSON)
                    .retrieve()
                    .bodyToMono(OrderSummary.class)
                    .blockOptional()
                    .orElseThrow(() -> new ExternalServiceException("Respuesta vacía de ms-orders"));
        } catch (WebClientResponseException.NotFound e) {
            throw new OrderNotFoundException("Pedido no encontrado");
        } catch (WebClientResponseException e) {
            throw new ExternalServiceException("Error llamando a ms-orders: " + e.getRawStatusCode(), e);
        } catch (Exception e) {
            throw new ExternalServiceException("Error inesperado llamando a ms-orders", e);
        }
    }
}
