package com.example.keycloak;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.convert.converter.Converter;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.web.SecurityFilterChain;

import java.util.Collection;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.disable())
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health", "/api/public").permitAll()
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth -> oauth
                .jwt(jwt -> jwt.jwtAuthenticationConverter(keycloakJwtAuthenticationConverter()))
            );

        return http.build();
    }

    @Bean
    Converter<Jwt, ? extends AbstractAuthenticationToken> keycloakJwtAuthenticationConverter() {
        return jwt -> {
            Collection<GrantedAuthority> authorities = Stream.concat(
                extractRealmRoles(jwt).stream(),
                extractClientRoles(jwt).stream()
            ).map(role -> new SimpleGrantedAuthority("ROLE_" + role))
             .map(GrantedAuthority.class::cast)
             .toList();

            return new JwtAuthenticationToken(jwt, authorities, jwt.getClaimAsString("preferred_username"));
        };
    }

    /**
     * This method is used to extract the role from realm_access claim which is realm roles
     * @param jwt
     * @return List<String>
     */
    private List<String> extractRealmRoles(Jwt jwt) {
        Map<String, Object> realmAccess = jwt.getClaim("realm_access");
        if (realmAccess == null) {
            return Collections.emptyList();
        }
        Object roles = realmAccess.get("roles");
        if (!(roles instanceof Collection<?> collection)) {
            return Collections.emptyList();
        }
        return collection.stream().filter(String.class::isInstance).map(String.class::cast).toList();
    }

    /**
     * This method is used to extract the role from resource_access claim which is client roles
     * @param jwt
     * @return List<String>
     */
    private List<String> extractClientRoles(Jwt jwt) {
        Map<String, Object> resourceAccess = jwt.getClaim("resource_access");
        if (resourceAccess == null) {
            return Collections.emptyList();
        }
        Object client = resourceAccess.get("spring-boot-api");
        if (!(client instanceof Map<?, ?> clientMap)) {
            return Collections.emptyList();
        }
        Object roles = clientMap.get("roles");
        if (!(roles instanceof Collection<?> collection)) {
            return Collections.emptyList();
        }
        return collection.stream().filter(String.class::isInstance).map(String.class::cast).toList();
    }
}
