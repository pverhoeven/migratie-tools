package local.migratietools;

import org.openrewrite.ExecutionContext;
import org.openrewrite.Recipe;
import org.openrewrite.TreeVisitor;
import org.openrewrite.internal.ListUtils;
import org.openrewrite.java.JavaIsoVisitor;
import org.openrewrite.java.MethodMatcher;
import org.openrewrite.java.tree.J;

/** Voorbeeld van een Java-recept: verwijdert achtergebleven debug-output. */
public class VerwijderSystemOutPrintln extends Recipe {

    private static final MethodMatcher PRINTLN = new MethodMatcher("java.io.PrintStream println(..)");

    @Override
    public String getDisplayName() {
        return "Verwijder System.out.println";
    }

    @Override
    public String getDescription() {
        return "Verwijdert statements die met `System.out.println` naar de console schrijven.";
    }

    @Override
    public TreeVisitor<?, ExecutionContext> getVisitor() {
        return new JavaIsoVisitor<>() {
            @Override
            public J.Block visitBlock(J.Block block, ExecutionContext ctx) {
                J.Block b = super.visitBlock(block, ctx);
                return b.withStatements(ListUtils.map(b.getStatements(), s ->
                        s instanceof J.MethodInvocation m && PRINTLN.matches(m) && isSystemOut(m) ? null : s));
            }

            private boolean isSystemOut(J.MethodInvocation m) {
                return m.getSelect() instanceof J.FieldAccess f
                        && f.getSimpleName().equals("out")
                        && f.getTarget() instanceof J.Identifier t
                        && t.getSimpleName().equals("System");
            }
        };
    }
}
