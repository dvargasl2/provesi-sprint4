package com.provesi.securityguard;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class SecurityGuardApplication {

    public static void main(String[] args) {
        SpringApplication.run(SecurityGuardApplication.class, args);
    }
}
