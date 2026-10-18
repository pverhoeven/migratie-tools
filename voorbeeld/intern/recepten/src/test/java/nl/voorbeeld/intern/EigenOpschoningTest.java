package nl.voorbeeld.intern;

import static org.openrewrite.java.Assertions.java;

import org.junit.jupiter.api.Test;
import org.openrewrite.test.RecipeSpec;
import org.openrewrite.test.RewriteTest;

class EigenOpschoningTest implements RewriteTest {

    @Override
    public void defaults(RecipeSpec spec) {
        spec.recipeFromResources("nl.voorbeeld.intern.EigenOpschoning");
    }

    @Test
    void ruimtOpMetDeIngebouwdeRecepten() {
        rewriteRun(java(
                """
                import java.util.Map;

                class A {
                    int aantal(int n) {
                        System.out.println("aantal: " + n);
                        return n;
                    }
                }
                """,
                """
                class A {
                    int aantal(int n) {
                        return n;
                    }
                }
                """));
    }
}
