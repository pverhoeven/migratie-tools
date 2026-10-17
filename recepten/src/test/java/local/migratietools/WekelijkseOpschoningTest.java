package local.migratietools;

import static org.openrewrite.java.Assertions.java;

import org.junit.jupiter.api.Test;
import org.openrewrite.java.JavaParser;
import org.openrewrite.test.RecipeSpec;
import org.openrewrite.test.RewriteTest;

class WekelijkseOpschoningTest implements RewriteTest {

    @Override
    public void defaults(RecipeSpec spec) {
        spec.recipeFromResources("local.migratietools.WekelijkseOpschoning")
                .parser(JavaParser.fromJavaVersion().dependsOn(
                        """
                        package org.springframework.beans.factory.annotation;
                        public @interface Autowired {}
                        """,
                        """
                        package org.slf4j;
                        public interface Logger {
                            void info(String msg);
                            void info(String format, Object arg);
                            void info(String format, Object... args);
                        }
                        """));
    }

    @Test
    void ruimtDodeCodeEnOmslachtigeBooleansOp() {
        rewriteRun(java(
                """
                import java.util.List;

                class Klant {
                    private int ongebruikt;

                    boolean zonderNaam(String naam) {
                        if (naam.isEmpty()) {
                            return true;
                        } else {
                            return false;
                        }
                    }
                }
                """,
                """
                class Klant {

                    boolean zonderNaam(String naam) {
                        return naam.isEmpty();
                    }
                }
                """));
    }

    @Test
    void haaltOverbodigeAutowiredOpConstructorWeg() {
        rewriteRun(java(
                """
                import org.springframework.beans.factory.annotation.Autowired;

                class KlantService {
                    private final String naam;

                    @Autowired
                    KlantService(String naam) {
                        this.naam = naam;
                    }

                    String naam() {
                        return naam;
                    }
                }
                """,
                """
                class KlantService {
                    private final String naam;

                    KlantService(String naam) {
                        this.naam = naam;
                    }

                    String naam() {
                        return naam;
                    }
                }
                """));
    }

    @Test
    void maaktLogregelsGeparametriseerdZonderLambda() {
        rewriteRun(java(
                """
                import java.util.List;
                import org.slf4j.Logger;

                class Regels {
                    private final Logger log;

                    Regels(Logger log) {
                        this.log = log;
                    }

                    void tel(List<String> regels) {
                        log.info("aantal regels: " + regels.size());
                    }
                }
                """,
                """
                import java.util.List;
                import org.slf4j.Logger;

                class Regels {
                    private final Logger log;

                    Regels(Logger log) {
                        this.log = log;
                    }

                    void tel(List<String> regels) {
                        log.info("aantal regels: {}", regels.size());
                    }
                }
                """));
    }

    @Test
    void laatSchoneCodeOngemoeid() {
        rewriteRun(java(
                """
                class Bestelling {
                    private final int aantal;

                    Bestelling(int aantal) {
                        this.aantal = aantal;
                    }

                    int aantal() {
                        return aantal;
                    }
                }
                """));
    }
}
