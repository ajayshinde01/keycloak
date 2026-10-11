package com.example.keycloak;

import org.springframework.security.core.Authentication;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class SecureController {

    /**
     * This is public endpoint can be accessed by anyone without token
     * @return Map<String, Object>
     */
    @GetMapping("/api/public")
    public Map<String, Object> publicEndpoint() {
        return Map.of("message", "Public endpoint - no token required");
    }

    /**
     * This endpoint list outs all roles provided to user and its username
     * @param authentication
     * @return Map<String, Object>
     */
    @GetMapping("/api/me")
    public Map<String, Object> me(Authentication authentication) {
        return Map.of(
            "username", authentication.getName(),
            "authorities", authentication.getAuthorities().stream().map(Object::toString).toList()
        );
    }

    /**
     * This endpoint can be accessed by users having USER and ADMIN as role
     * @return Map<String, Object>
     */
    @GetMapping("/api/accounts")
    @PreAuthorize("hasAnyRole('USER', 'ADMIN')")
    public Map<String, Object> accounts() {
        return Map.of("message", "USER or ADMIN can access accounts");
    }

    /**
     * This endpoint can be accessed by users having ADMIN role
     * @return Map<String, Object>
     */
    @PostMapping("/api/accounts")
    @PreAuthorize("hasRole('ADMIN')")
    public Map<String, Object> createAccount() {
        return Map.of("message", "ADMIN can create accounts");
    }

    /**
     * This endpoint can be accessed by users having ADMIN role
     * @return Map<String, Object>
     */
    @DeleteMapping("/api/accounts/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public Map<String, Object> deleteAccount(@PathVariable String id) {
        return Map.of("message", "ADMIN can delete account", "id", id);
    }
}
