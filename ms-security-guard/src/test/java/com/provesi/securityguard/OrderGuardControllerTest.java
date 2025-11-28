package com.provesi.securityguard;

import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.provesi.securityguard.controller.OrderGuardController;
import com.provesi.securityguard.security.VendorIdExtractor;
import com.provesi.securityguard.service.ForbiddenAccessException;
import com.provesi.securityguard.service.OrderGuardService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(controllers = OrderGuardController.class)
class OrderGuardControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private OrderGuardService orderGuardService;

    @MockBean
    private VendorIdExtractor vendorIdExtractor;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    @WithMockUser
    void returnsForbiddenWhenVendorMismatch() throws Exception {
        when(vendorIdExtractor.extractVendorId(null)).thenReturn("vendor-a");
        when(orderGuardService.authorizeAndFetch(anyLong(), anyString()))
                .thenThrow(new ForbiddenAccessException("El pedido no pertenece al vendedor autenticado"));

        mockMvc.perform(get("/orders/10/full"))
                .andExpect(status().isForbidden());
    }

    @Test
    @WithMockUser
    void returnsOkWhenServiceAllows() throws Exception {
        JsonNode stub = objectMapper.readTree("{\"ok\":true}");
        when(vendorIdExtractor.extractVendorId(null)).thenReturn("vendor-a");
        when(orderGuardService.authorizeAndFetch(anyLong(), anyString())).thenReturn(stub);

        mockMvc.perform(get("/orders/1/full"))
                .andExpect(status().isOk());
    }
}
