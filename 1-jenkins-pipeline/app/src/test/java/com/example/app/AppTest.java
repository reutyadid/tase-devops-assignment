package com.example.app;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class AppTest {

    @Test
    void greetingContainsName() {
        assertEquals("Hello, TASE!", App.greeting("TASE"));
    }
}
