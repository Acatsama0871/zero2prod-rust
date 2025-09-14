use sqlx::postgres::PgPoolOptions;
use std::net::TcpListener;
use zero2prod_rust::configuration::get_configuration;
use zero2prod_rust::email_client::EmailClient;
use zero2prod_rust::startup::run;
use zero2prod_rust::telemetry::{get_subscriber, init_subscriber};

#[tokio::main]
async fn main() -> Result<(), std::io::Error> {
    let subscriber = get_subscriber("zero2prod".into(), "info".into(), std::io::stdout);
    init_subscriber(subscriber);

    let configuration = get_configuration().expect("Failed to read configuration");
    let connection_pool =
        PgPoolOptions::new().connect_lazy_with(configuration.database.connection_options());
    let address = format!(
        "{}:{}",
        configuration.application.host, configuration.application.port
    );
    let listener = TcpListener::bind(address).expect("Failed to bind port 8000");
    let sender_email = configuration
        .email_client
        .sender()
        .expect("Invalid sender email address");
    let email_client = EmailClient::new(configuration.email_client.base_url, sender_email);
    run(listener, connection_pool, email_client)?.await
}
