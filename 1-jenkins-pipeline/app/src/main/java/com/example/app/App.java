package com.example.app;

/** Minimal application built and packed by the Jenkins pipeline. */
public final class App {

    private App() {
    }

    /** Pure logic, kept separate from printing so it can be unit tested. */
    static String greeting(String name) {
        return "Hello, " + name + "!";
    }

    public static void main(String[] args) {
        System.out.println(greeting("TASE"));
    }
}
