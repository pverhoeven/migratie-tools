package local.migratietools;

import static org.openrewrite.java.Assertions.java;

import org.junit.jupiter.api.Test;
import org.openrewrite.test.RecipeSpec;
import org.openrewrite.test.RewriteTest;

class VerwijderSystemOutPrintlnTest implements RewriteTest {

    @Override
    public void defaults(RecipeSpec spec) {
        spec.recipe(new VerwijderSystemOutPrintln());
    }

    @Test
    void verwijdertPrintln() {
        rewriteRun(java(
                """
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

    @Test
    void laatAndereOutputStaan() {
        rewriteRun(java(
                """
                class A {
                    void fout() {
                        System.err.println("fout");
                    }
                }
                """));
    }
}
