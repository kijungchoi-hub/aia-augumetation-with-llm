## 비식별화 매핑 기준

- 이 문서는 개인정보 마스킹 규칙 문서가 아니라, 반출용 비식별화 매핑 기준입니다.
- 원본 TEXT는 내부 처리와 학습에 그대로 사용합니다.
- 외부 반출본이 필요한 경우에만 아래 original_value -> pseudonym_value 매핑을 적용합니다.

| id | pii_type        | original_value                              | pseudonym_value                             |
| -- | --------------- | ------------------------------------------- | ------------------------------------------- |
| 1  | PERSON_CUSTOMER | 김민수                                         | 고객101                                       |
| 2  | PERSON_CUSTOMER | 이영희                                         | 고객102                                       |
| 3  | PERSON_CUSTOMER | 박철수                                         | 고객103                                       |
| 4  | PERSON_CUSTOMER | 최지훈                                         | 고객104                                       |
| 5  | PERSON_CUSTOMER | 정수빈                                         | 고객105                                       |
| 6  | PERSON_AGENT    | 박상담                                         | 상담사201                                      |
| 7  | PERSON_AGENT    | 김상담                                         | 상담사202                                      |
| 8  | PERSON_AGENT    | 이상담                                         | 상담사203                                      |
| 9  | PERSON_AGENT    | 최상담                                         | 상담사204                                      |
| 10 | PERSON_AGENT    | 정상담                                         | 상담사205                                      |
| 11 | PHONE           | 010-1234-5678                               | 010-5831-9427                               |
| 12 | PHONE           | 010-2345-6789                               | 010-7712-3304                               |
| 13 | PHONE           | 010-3456-7890                               | 010-6621-1189                               |
| 14 | PHONE           | 010-4567-8901                               | 010-9021-4456                               |
| 15 | PHONE           | 010-5678-9012                               | 010-3345-7788                               |
| 16 | POLICY_NO       | 12345678                                    | PN-83920174                                 |
| 17 | POLICY_NO       | 23456789                                    | PN-58210433                                 |
| 18 | POLICY_NO       | 34567890                                    | PN-10458219                                 |
| 19 | POLICY_NO       | 45678901                                    | PN-77390122                                 |
| 20 | POLICY_NO       | 56789012                                    | PN-66218877                                 |
| 21 | ACCOUNT_NO      | 123-456-789012                              | AC-5821-993847                              |
| 22 | ACCOUNT_NO      | 234-567-890123                              | AC-1442-662918                              |
| 23 | ACCOUNT_NO      | 345-678-901234                              | AC-7712-448221                              |
| 24 | ACCOUNT_NO      | 456-789-012345                              | AC-9901-228877                              |
| 25 | ACCOUNT_NO      | 567-890-123456                              | AC-6611-337744                              |
| 26 | ADDRESS         | 서울 강남구                                      | 수도권 지역                                      |
| 27 | ADDRESS         | 서울 송파구                                      | 수도권 지역2                                     |
| 28 | ADDRESS         | 부산 해운대구                                     | 영남 지역                                       |
| 29 | ADDRESS         | 대구 수성구                                      | 영남 지역2                                      |
| 30 | ADDRESS         | 광주 서구                                       | 호남 지역                                       |
| 31 | ORG_BRANCH      | 강남지점                                        | 수도권 지점                                      |
| 32 | ORG_BRANCH      | 송파지점                                        | 수도권 지점2                                     |
| 33 | ORG_BRANCH      | 해운대지점                                       | 영남 지점                                       |
| 34 | ORG_BRANCH      | 대구지점                                        | 영남 지점2                                      |
| 35 | ORG_BRANCH      | 광주지점                                        | 호남 지점                                       |
| 36 | HOSPITAL        | 서울아산병원                                      | 상급종합병원                                      |
| 37 | HOSPITAL        | 삼성서울병원                                      | 상급종합병원2                                     |
| 38 | HOSPITAL        | 부산백병원                                       | 지역 거점병원                                     |
| 39 | HOSPITAL        | 대구파티마병원                                     | 지역 거점병원2                                    |
| 40 | HOSPITAL        | 광주기독병원                                      | 지역 병원                                       |
| 41 | EMAIL           | [test@naver.com](mailto:test@naver.com)     | [user101@test.com](mailto:user101@test.com) |
| 42 | EMAIL           | [user1@gmail.com](mailto:user1@gmail.com)   | [user102@test.com](mailto:user102@test.com) |
| 43 | EMAIL           | [abc@daum.net](mailto:abc@daum.net)         | [user103@test.com](mailto:user103@test.com) |
| 44 | EMAIL           | [xyz@yahoo.com](mailto:xyz@yahoo.com)       | [user104@test.com](mailto:user104@test.com) |
| 45 | EMAIL           | [sample@kakao.com](mailto:sample@kakao.com) | [user105@test.com](mailto:user105@test.com) |
| 46 | CARD_NO         | 1234-5678-****-1111                         | CARD-5821-1111                              |
| 47 | CARD_NO         | 2345-6789-****-2222                         | CARD-6621-2222                              |
| 48 | CARD_NO         | 3456-7890-****-3333                         | CARD-7712-3333                              |
| 49 | CARD_NO         | 4567-8901-****-4444                         | CARD-9901-4444                              |
| 50 | CARD_NO         | 5678-9012-****-5555                         | CARD-6611-5555                              |

