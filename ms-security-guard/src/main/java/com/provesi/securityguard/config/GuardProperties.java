package com.provesi.securityguard.config;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "guard")
public class GuardProperties {

    private Services services = new Services();
    private Http http = new Http();
    private String vendorClaim = "vendorId";

    public Services getServices() {
        return services;
    }

    public Http getHttp() {
        return http;
    }

    public String getVendorClaim() {
        return vendorClaim;
    }

    public void setVendorClaim(String vendorClaim) {
        this.vendorClaim = vendorClaim;
    }

    public static class Services {
        private String ordersBaseUrl = "http://localhost:8001";
        private String orderDetailBaseUrl = "http://localhost:8080";

        public String getOrdersBaseUrl() {
            return ordersBaseUrl;
        }

        public void setOrdersBaseUrl(String ordersBaseUrl) {
            this.ordersBaseUrl = ordersBaseUrl;
        }

        public String getOrderDetailBaseUrl() {
            return orderDetailBaseUrl;
        }

        public void setOrderDetailBaseUrl(String orderDetailBaseUrl) {
            this.orderDetailBaseUrl = orderDetailBaseUrl;
        }
    }

    public static class Http {
        private Duration connectTimeout = Duration.ofSeconds(2);
        private Duration readTimeout = Duration.ofSeconds(2);

        public Duration getConnectTimeout() {
            return connectTimeout;
        }

        public void setConnectTimeout(Duration connectTimeout) {
            this.connectTimeout = connectTimeout;
        }

        public Duration getReadTimeout() {
            return readTimeout;
        }

        public void setReadTimeout(Duration readTimeout) {
            this.readTimeout = readTimeout;
        }
    }
}
