use crate::{domain::{NewSubscriber, SubscriberEmail, SubscriberName}, email_client::{self, EmailClient}};
use actix_web::{HttpResponse, web};
use chrono::Utc;
use sqlx::PgPool;
use uuid::Uuid;

#[derive(serde::Deserialize, Debug)]
pub struct FormData {
    email: String,
    name: String,
}

impl TryFrom<FormData> for NewSubscriber {
    type Error = String;

    fn try_from(form: FormData) -> Result<Self, Self::Error> {
        let name = SubscriberName::parse(form.name.clone())?;
        let email = SubscriberEmail::parse(form.email.clone())?;
        Ok(NewSubscriber { email, name })
    }
}

#[tracing::instrument(
    name = "Adding a new subscriber",
    skip(form, pool, email_client),
    fields(
        subscriber_email = %form.email,
        subscriber_name = %form.name
    )
)]
pub async fn subscribe(form: web::Form<FormData>, pool: web::Data<PgPool>, email_client: web::Data<EmailClient>) -> HttpResponse {
    let new_subscriber = match form.0.try_into() {
        Ok(subscriber) => subscriber,
        Err(e) => {
            tracing::error!("Request ID - Failed to parse subscriber: {:?}", e);
            return HttpResponse::BadRequest().body(format!("Invalid input: {}", e));
        }
    };
    if insert_subscriber(&new_subscriber, &pool).await.is_err() {
        return HttpResponse::InternalServerError().finish();
    }

    if email_client.send_email(new_subscriber.email, "Welcome", "Welcome to our newsletter", "Welcome to our newsletter").await.is_err() {
        return HttpResponse::InternalServerError().finish();
    }

    HttpResponse::Ok().finish()
}

#[tracing::instrument(
    name = "Saving new subscriber details in database",
    skip(new_subscriber, db_pool)
)]
pub async fn insert_subscriber(
    new_subscriber: &NewSubscriber,
    db_pool: &PgPool,
) -> Result<(), sqlx::Error> {
    sqlx::query!(
        r#"
        INSERT INTO subscriptions (id, email, name, subscribed_at, status)
        VALUES ($1, $2, $3, $4, 'confirmed')
        "#,
        Uuid::new_v4(),
        new_subscriber.email.as_ref(),
        new_subscriber.name.as_ref(),
        Utc::now()
    )
    .execute(db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to execute query: {:?}", e);
        e
    })?;
    Ok(())
}
