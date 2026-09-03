import com.sun.net.httpserver.HttpServer;
import java.io.OutputStream;
import java.net.InetSocketAddress;

public class Main {
    public static void main(String[] args) throws Exception {
        HttpServer httpServer = HttpServer.create(new InetSocketAddress(8080), 0);
        httpServer.createContext("/", exchange -> {
            String greeting = "<h1>Hello World from Abhi's Java app!</h1>";
            exchange.sendResponseHeaders(200, greeting.getBytes().length);
            OutputStream os = exchange.getResponseBody();
            os.write(greeting.getBytes());
            os.close();
        });
        httpServer.setExecutor(null);
        System.out.println("Java app listening on port 8080");
        httpServer.start();
    }
}
