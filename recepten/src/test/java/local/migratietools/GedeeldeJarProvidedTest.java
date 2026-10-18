package local.migratietools;

import static org.openrewrite.maven.Assertions.pomXml;

import java.nio.file.Path;

import org.junit.jupiter.api.Test;
import org.openrewrite.InMemoryExecutionContext;
import org.openrewrite.maven.MavenExecutionContextView;
import org.openrewrite.maven.tree.MavenRepository;
import org.openrewrite.test.RecipeSpec;
import org.openrewrite.test.RewriteTest;

class GedeeldeJarProvidedTest implements RewriteTest {

    // nl.voorbeeld:gedeelde-jar staat niet in Maven Central; de test gebruikt een eigen
    // mini-repository met alleen de pom als lokale repository, zodat hij ook werkt zonder
    // het voorbeeld (bv. op Jenkins).
    private static final String REPOSITORY = Path.of("src/test/resources/maven-repo").toAbsolutePath().toUri().toString();

    @Override
    public void defaults(RecipeSpec spec) {
        MavenExecutionContextView ctx = MavenExecutionContextView.view(new InMemoryExecutionContext());
        ctx.setLocalRepository(MavenRepository.builder().id("test").uri(REPOSITORY).knownToExist(true).build());
        spec.recipeFromResources("local.migratietools.GedeeldeJarProvided").executionContext(ctx);
    }

    @Test
    void zetDeGedeeldeJarOpProvided() {
        rewriteRun(pomXml(
                """
                <project>
                    <groupId>nl.voorbeeld</groupId>
                    <artifactId>afnemer</artifactId>
                    <version>1.0.0</version>
                    <dependencies>
                        <dependency>
                            <groupId>nl.voorbeeld</groupId>
                            <artifactId>gedeelde-jar</artifactId>
                            <version>1.0.0</version>
                        </dependency>
                    </dependencies>
                </project>
                """,
                """
                <project>
                    <groupId>nl.voorbeeld</groupId>
                    <artifactId>afnemer</artifactId>
                    <version>1.0.0</version>
                    <dependencies>
                        <dependency>
                            <groupId>nl.voorbeeld</groupId>
                            <artifactId>gedeelde-jar</artifactId>
                            <version>1.0.0</version>
                            <scope>provided</scope>
                        </dependency>
                    </dependencies>
                </project>
                """));
    }

    @Test
    void laatAndereServicesOngemoeid() {
        rewriteRun(pomXml(
                """
                <project>
                    <groupId>nl.voorbeeld</groupId>
                    <artifactId>geen-afnemer</artifactId>
                    <version>1.0.0</version>
                </project>
                """));
    }
}
