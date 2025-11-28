package com.provesi.securityguard.config;

import io.netty.channel.ChannelOption;
import java.time.Duration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.web.reactive.function.client.ExchangeStrategies;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.netty.http.client.HttpClient;

@Configuration
public class WebClientConfig {

    @Bean
    public WebClient.Builder webClientBuilder(GuardProperties guardProperties) {
        Duration connect = guardProperties.getHttp().getConnectTimeout();
        Duration read = guardProperties.getHttp().getReadTimeout();

        HttpClient client = HttpClient.create()
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, (int) connect.toMillis())
                .responseTimeout(read);

        return WebClient.builder()
                .clientConnector(new ReactorClientHttpConnector(client))
                .exchangeStrategies(ExchangeStrategies.builder()
                        .codecs(cfg -> cfg.defaultCodecs().maxInMemorySize(1_048_576))
                        .build());
    }
}
