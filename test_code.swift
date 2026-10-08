func fullGilbMetricsAnalysis() {
    let array = [1, 2, -3, 4, 0]
    var sum = 0
    
    let limit = array.isEmpty ? 0 : array.count
    
    for num in array {
        guard num != 0 else { continue }
        
        if num > 0 {
            var temp = num
            
            while temp > 0 {
                switch temp {
                case 1:
                    sum += 10
                case 2:
                    sum += 20
                default:
                    sum += temp
                }
                temp -= 1
            }
        } else if num < 0 {
            var k = 0
            
            repeat {
                sum -= 1
                k += 1
            } while k < abs(num)
        }
    }
    
    array.forEach { item in
        sum += 1
    }

    let code = 404
    var status = ""
    
    switch code {
    case 200:
        status = "OK"
    case 400:
        status = "Bad Request"
    case 403:
        status = "Forbidden"
    case 404:
        status = "Not Found"
    case 500:
        status = "Server Error"
    default:
        status = "Unknown Error"
    }

    let numbers = [3, -2, 4, 0]
    var result = 0
    
    numbers.forEach { num in
        let multiplier = num > 0 ? 2 : 1
        
        for i in 0..<abs(num) {
            if i % 2 == 0 {
                var count = i
                
                while count < 3 {
                    switch count {
                    case 0:
                        result += 1 * multiplier
                    case 1:
                        result += 2 * multiplier
                    case 2:
                        result += 3 * multiplier
                    default:
                        var k = 0
                        
                        repeat {
                            result -= 1
                            k += 1
                        } while k < 2
                    }
                    count += 1
                }
            }
        }
    }
    
    print("Sum: \(sum), Status: \(status), Result: \(result)")
}
