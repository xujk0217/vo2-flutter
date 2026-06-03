abstract interface class RawSensorPayloadParser<T> {
  const RawSensorPayloadParser();

  T? tryParse(String payload);
}
