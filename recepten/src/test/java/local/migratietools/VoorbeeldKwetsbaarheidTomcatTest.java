package local.migratietools;

import static org.openrewrite.maven.Assertions.pomXml;

import org.junit.jupiter.api.Test;
import org.openrewrite.InMemoryExecutionContext;
import org.openrewrite.maven.MavenExecutionContextView;
import org.openrewrite.maven.MavenSettings;
import org.openrewrite.test.RecipeSpec;
import org.openrewrite.test.RewriteTest;

// Haalt tomcat-embed-core uit Maven Central, of via de mirror uit ~/.m2/settings.xml: zonder
// die instellingen gaat de test van OpenRewrite altijd rechtstreeks naar Maven Central, en
// dat lukt niet op een netwerk dat alleen een eigen mirror (bv. Nexus) toelaat.
class VoorbeeldKwetsbaarheidTomcatTest implements RewriteTest {

    @Override
    public void defaults(RecipeSpec spec) {
        MavenExecutionContextView ctx = MavenExecutionContextView.view(new InMemoryExecutionContext());
        MavenSettings settings = MavenSettings.readMavenSettingsFromDisk(ctx);
        if (settings != null) {
            ctx.setMavenSettings(settings);
        }
        spec.recipeFromResources("local.migratietools.VoorbeeldKwetsbaarheidTomcat").executionContext(ctx);
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
