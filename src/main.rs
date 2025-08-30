use sqlx::PgPool;
use std::net::TcpListener;
use zero2prod_rust::configuration::get_configuration;
use zero2prod_rust::startup::run;
use zero2prod_rust::telemetry::{get_subscriber, init_subscriber};

#[tokio::main]
async fn main() -> Result<(), std::io::Error> {
    let subscriber = get_subscriber("zero2prod".into(), "info".into(), std::io::stdout);
    init_subscriber(subscriber);

    let configuration = get_configuration().expect("Failed to read configuration");
    let connection = PgPool::connect_lazy(&configuration.database.connection_string())
        .expect("Failed to connect to postgres");
    let address = format!(
        "{}:{}",
        configuration.application.host, configuration.application.port
    );
    let listener = TcpListener::bind(address).expect("Failed to bind port 8000");
    run(listener, connection)?.await
}
