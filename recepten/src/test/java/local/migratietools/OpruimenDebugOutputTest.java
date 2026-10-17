package local.migratietools;

import static org.openrewrite.java.Assertions.java;

import org.junit.jupiter.api.Test;
import org.openrewrite.test.RecipeSpec;
import org.openrewrite.test.RewriteTest;

class OpruimenDebugOutputTest implements RewriteTest {

    @Override
    public void defaults(RecipeSpec spec) {
        spec.recipeFromResources("local.migratietools.OpruimenDebugOutput");
    }

    @Test
    void verwijdertPrintlnEnOngebruikteImport() {
        rewriteRun(java(
                """
                import java.util.Arrays;

                class A {
                    void debug(int[] waarden) {
                        System.out.println(Arrays.toString(waarden));
                    }
                }
                """,
                """
                class A {
                    void debug(int[] waarden) {
                    }
                }
                """));
    }
}
