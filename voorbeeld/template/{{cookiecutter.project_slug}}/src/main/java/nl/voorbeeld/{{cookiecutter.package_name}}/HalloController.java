package nl.voorbeeld.{{ cookiecutter.package_name }};

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HalloController {

    @GetMapping("/hallo")
    public String hallo() {
        return "Hallo van {{ cookiecutter.project_name }}";
    }
}
