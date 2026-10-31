//! The parts of Symbolon that bringmeback calls from Dart. Group keys stay inside Rust: Dart only
//! ever sees public values (topics, fingerprints, public keys) and the device's own private key, which
//! it has to store.

use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;
use symbolon::channel::Channel;
use symbolon::handshake::{self, Handshake, StaticKeypair};
use symbolon::keys::{KeySchedule, Purpose};
use symbolon::seal::Sealer;

/// Separates bringmeback's keys from any other app using Symbolon with the same secret.
const CONTEXT: &[u8] = b"bringmeback/v1";

fn key32(bytes: &[u8]) -> Result<[u8; 32]> {
    bytes.try_into().map_err(|_| anyhow!("expected 32 bytes"))
}

/// Every key of a sync group, derived from its 32-byte group secret.
#[frb(opaque)]
pub struct GroupKeys {
    keys: KeySchedule,
}

impl GroupKeys {
    #[frb(sync)]
    pub fn new(secret: Vec<u8>) -> Result<GroupKeys> {
        Ok(Self { keys: KeySchedule::new(CONTEXT, &secret)? })
    }

    /// A relay topic only group members can compute.
    #[frb(sync)]
    pub fn topic(&self, label: Vec<u8>) -> Vec<u8> {
        self.keys.topic(&label).to_vec()
    }

    /// Six bytes to show on every device so people can compare them.
    #[frb(sync)]
    pub fn fingerprint(&self) -> Vec<u8> {
        self.keys.fingerprint().to_vec()
    }

    /// Encrypts a signalling message for the relay.
    #[frb(sync)]
    pub fn seal(&self, plaintext: Vec<u8>, aad: Vec<u8>) -> Result<Vec<u8>> {
        Ok(Sealer::new(&self.keys).seal(&plaintext, &aad)?)
    }

    #[frb(sync)]
    pub fn open(&self, sealed: Vec<u8>, aad: Vec<u8>) -> Result<Vec<u8>> {
        Ok(Sealer::new(&self.keys).open(&sealed, &aad)?)
    }
}

/// This device's long-term key for the Noise handshake.
#[frb(opaque)]
pub struct DeviceKey {
    keypair: StaticKeypair,
}

impl DeviceKey {
    #[frb(sync)]
    pub fn generate() -> Result<DeviceKey> {
        Ok(Self { keypair: StaticKeypair::generate()? })
    }

    #[frb(sync)]
    pub fn from_private(private_key: Vec<u8>) -> Result<DeviceKey> {
        Ok(Self { keypair: StaticKeypair::from_private(&private_key)? })
    }

    #[frb(sync)]
    pub fn public_key(&self) -> Vec<u8> {
        self.keypair.public().to_vec()
    }

    /// Only for storing the key on this device.
    #[frb(sync)]
    pub fn private_key(&self) -> Vec<u8> {
        self.keypair.private().to_vec()
    }
}

/// Whether this device starts the handshake with `remote_public`.
#[frb(sync)]
pub fn initiates(local_public: Vec<u8>, remote_public: Vec<u8>) -> Result<bool> {
    Ok(handshake::initiates(&key32(&local_public)?, &key32(&remote_public)?))
}

#[frb(opaque)]
pub struct NoiseHandshake {
    handshake: Option<Handshake>,
}

impl NoiseHandshake {
    #[frb(sync)]
    pub fn initiator(
        device: &DeviceKey,
        remote_public: Vec<u8>,
        group: &GroupKeys,
        prologue: Vec<u8>,
    ) -> Result<NoiseHandshake> {
        let psk = group.keys.derive(Purpose::NoisePsk);
        let hs = Handshake::initiator(&device.keypair, &key32(&remote_public)?, &psk, &prologue)?;
        Ok(Self { handshake: Some(hs) })
    }

    #[frb(sync)]
    pub fn responder(device: &DeviceKey, group: &GroupKeys, prologue: Vec<u8>) -> Result<NoiseHandshake> {
        let psk = group.keys.derive(Purpose::NoisePsk);
        Ok(Self { handshake: Some(Handshake::responder(&device.keypair, &psk, &prologue)?) })
    }

    fn handshake(&mut self) -> Result<&mut Handshake> {
        self.handshake.as_mut().ok_or_else(|| anyhow!(symbolon::Error::HandshakeFinished))
    }

    #[frb(sync)]
    pub fn write_message(&mut self, payload: Vec<u8>) -> Result<Vec<u8>> {
        Ok(self.handshake()?.write_message(&payload)?)
    }

    #[frb(sync)]
    pub fn read_message(&mut self, message: Vec<u8>) -> Result<Vec<u8>> {
        Ok(self.handshake()?.read_message(&message)?)
    }

    #[frb(sync)]
    pub fn is_finished(&self) -> bool {
        self.handshake.as_ref().is_some_and(Handshake::is_finished)
    }

    /// The other device's public key, known once its first message has been read.
    #[frb(sync)]
    pub fn remote_static(&self) -> Option<Vec<u8>> {
        self.handshake.as_ref()?.remote_static().map(|k| k.to_vec())
    }

    /// Ends the handshake; this object can't be used afterwards.
    #[frb(sync)]
    pub fn into_channel(&mut self) -> Result<SecureChannel> {
        let hs = self.handshake.take().ok_or_else(|| anyhow!(symbolon::Error::HandshakeFinished))?;
        Ok(SecureChannel { channel: hs.into_channel()? })
    }
}

/// Encrypted messages after the handshake. Any rejected message closes it.
#[frb(opaque)]
pub struct SecureChannel {
    channel: Channel,
}

impl SecureChannel {
    #[frb(sync)]
    pub fn encrypt(&mut self, plaintext: Vec<u8>) -> Result<Vec<u8>> {
        Ok(self.channel.encrypt(&plaintext)?)
    }

    #[frb(sync)]
    pub fn decrypt(&mut self, ciphertext: Vec<u8>) -> Result<Vec<u8>> {
        Ok(self.channel.decrypt(&ciphertext)?)
    }

    #[frb(sync)]
    pub fn is_open(&self) -> bool {
        self.channel.is_open()
    }

    #[frb(sync)]
    pub fn max_plaintext() -> usize {
        symbolon::channel::MAX_PLAINTEXT
    }
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
