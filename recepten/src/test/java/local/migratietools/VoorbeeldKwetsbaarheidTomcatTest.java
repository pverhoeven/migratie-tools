package local.migratietools;

import static org.openrewrite.maven.Assertions.pomXml;

import org.junit.jupiter.api.Test;
import org.openrewrite.test.RecipeSpec;
import org.openrewrite.test.RewriteTest;

// Haalt tomcat-embed-core uit Maven Central (of de mirror van de agent).
class VoorbeeldKwetsbaarheidTomcatTest implements RewriteTest {

    @Override
    public void defaults(RecipeSpec spec) {
        spec.recipeFromResources("local.migratietools.VoorbeeldKwetsbaarheidTomcat");
    }

    @Test
    void hoogtEenTeLageVersieOp() {
        rewriteRun(pomXml(
                """
                <project>
                    <groupId>nl.voorbeeld</groupId>
                    <artifactId>service</artifactId>
                    <version>1.0.0</version>
                    <dependencies>
                        <dependency>
                            <groupId>org.apache.tomcat.embed</groupId>
                            <artifactId>tomcat-embed-core</artifactId>
                            <version>10.1.46</version>
                        </dependency>
                    </dependencies>
                </project>
                """,
                """
                <project>
                    <groupId>nl.voorbeeld</groupId>
                    <artifactId>service</artifactId>
                    <version>1.0.0</version>
                    <dependencies>
                        <dependency>
                            <groupId>org.apache.tomcat.embed</groupId>
                            <artifactId>tomcat-embed-core</artifactId>
                            <version>10.1.61</version>
                        </dependency>
                    </dependencies>
                </project>
                """));
    }

    @Test
    void laatEenVeiligeVersieOngemoeid() {
        rewriteRun(pomXml(
                """
                <project>
                    <groupId>nl.voorbeeld</groupId>
                    <artifactId>service</artifactId>
                    <version>1.0.0</version>
                    <dependencies>
                        <dependency>
                            <groupId>org.apache.tomcat.embed</groupId>
                            <artifactId>tomcat-embed-core</artifactId>
                            <version>10.1.61</version>
                        </dependency>
                    </dependencies>
                </project>
                """));
    }
}
