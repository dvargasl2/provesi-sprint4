package com.provesi.securityguard.client;

import com.fasterxml.jackson.databind.JsonNode;
import com.provesi.securityguard.config.GuardProperties;
import com.provesi.securityguard.service.ExternalServiceException;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;

@Component
public class OrderDetailClient {

    private final WebClient client;

    public OrderDetailClient(WebClient.Builder builder, GuardProperties guardProperties) {
        this.client = builder.baseUrl(guardProperties.getServices().getOrderDetailBaseUrl()).build();
    }

    public JsonNode fetchFullOrder(long orderId) {
        try {
            return client.get()
                    .uri("/orders/{id}/full", orderId)
                    .accept(MediaType.APPLICATION_JSON)
                    .retrieve()
                    .bodyToMono(JsonNode.class)
                    .blockOptional()
                    .orElseThrow(() -> new ExternalServiceException("Respuesta vacía desde el agregador de detalle"));
        } catch (WebClientResponseException e) {
            throw new ExternalServiceException("Error llamando al agregador de detalle: " + e.getRawStatusCode(), e);
        } catch (Exception e) {
            throw new ExternalServiceException("Error inesperado llamando al agregador de detalle", e);
        }
    }
}
